// lib/features/opinions/presentation/screens/anonymous_profile_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/providers/profile_providers.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/error_state.dart';


class AnonymousProfileScreen extends ConsumerStatefulWidget {
  final String userId;

  const AnonymousProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<AnonymousProfileScreen> createState() => _AnonymousProfileScreenState();
}

class _AnonymousProfileScreenState extends ConsumerState<AnonymousProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Load user's opinions
    Future.microtask(() {
      ref.read(profileOpinionsProvider(widget.userId).future);
      ref.read(profileFollowerCountProvider(widget.userId).future);
      ref.read(followStatusProvider(widget.userId).future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currentUserId = ref.read(currentUserIdProvider);
    final isOwnProfile = currentUserId == widget.userId;

    final profileStatus = ref.watch(userProfileStatusProvider(widget.userId));
    final followerCount = ref.watch(profileFollowerCountProvider(widget.userId));
    final followStatus = ref.watch(followStatusProvider(widget.userId));
    final opinionsAsync = ref.watch(profileOpinionsProvider(widget.userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Profile header
          Container(
            padding: EdgeInsets.all(Spacing.lg.w),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withOpacity(0.1),
                  width: BorderWidthTokens.hairline,
                ),
              ),
            ),
            child: Column(
              children: [
                // No avatar, no name - just status and follower count
                // Relationship status
                profileStatus.when(
                  loading: () => const CircularProgressIndicator(),
                  error: (error, stack) => const SizedBox.shrink(),
                  data: (status) {
                    final statusDisplay = _getStatusDisplay(status);
                    return Text(
                      statusDisplay,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    );
                  },
                ),
                Gap(Spacing.sm.h),
                // Follower count (shown here, not on feed cards)
                followerCount.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stack) => const SizedBox.shrink(),
                  data: (count) {
                    return Text(
                      '$count follower${count != 1 ? 's' : ''}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    );
                  },
                ),
                Gap(Spacing.md.h),
                // Follow button (only if not own profile)
                if (!isOwnProfile)
                  followStatus.when(
                    loading: () => const SizedBox.shrink(),
                    error: (error, stack) => const SizedBox.shrink(),
                    data: (isFollowing) {
                      return AppButton(
                        label: isFollowing ? 'Unfollow' : 'Follow',
                        onPressed: () async {
                          if (isFollowing) {
                            await ref.read(unfollowUserProvider(widget.userId).future);
                          } else {
                            await ref.read(followUserProvider(widget.userId).future);
                          }
                          ref.invalidate(followStatusProvider(widget.userId));
                          ref.invalidate(profileFollowerCountProvider(widget.userId));
                        },
                        size: ButtonSize.small,
                        customColor: isFollowing
                            ? colorScheme.surfaceContainerHighest
                            : colorScheme.primary,
                        textColor: isFollowing
                            ? colorScheme.onSurface
                            : colorScheme.onPrimary,
                      );
                    },
                  ),
              ],
            ),
          ),
          // Opinions list
          Expanded(
            child: opinionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ErrorStateWidget.from(error),
              data: (opinions) {
                if (opinions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined, size: 48, color: Colors.grey),
                        Gap(Spacing.md.h),
                        Text(
                          isOwnProfile ? 'You haven\'t posted any opinions yet' : 'No opinions yet',
                          style: textTheme.titleMedium,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: opinions.length,
                  itemBuilder: (context, index) {
                    final opinion = opinions[index];
                    return OpinionCard(
                      opinion: opinion,
                      showFollowButton: false, // No follow button on own profile
                      onCommentTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CommentThreadScreen(opinionId: opinion.id),
                          ),
                        );
                      },
                      onProfileTap: null, // Don't navigate to self
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusDisplay(String? status) {
    switch (status) {
      case 'single': return 'Single';
      case 'taken': return 'Taken';
      case 'figuring_it_out': return 'Figuring it out';
      case 'open': return 'Open';
      default: return '';
    }
  }
}
