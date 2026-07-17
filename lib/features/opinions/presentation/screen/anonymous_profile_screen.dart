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
  /// Opaque author handle (never a real user_id — FORUM.md §3).
  final String authorHandle;

  const AnonymousProfileScreen({super.key, required this.authorHandle});

  @override
  ConsumerState<AnonymousProfileScreen> createState() => _AnonymousProfileScreenState();
}

class _AnonymousProfileScreenState extends ConsumerState<AnonymousProfileScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(profileOpinionsProvider(widget.authorHandle).future);
      ref.read(authorProfileProvider(widget.authorHandle).future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final profileAsync = ref.watch(authorProfileProvider(widget.authorHandle));
    final isOwnProfile = profileAsync.valueOrNull?.isMine ?? false;
    final opinionsAsync = ref.watch(profileOpinionsProvider(widget.authorHandle));

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
            child: profileAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (error, stack) => const SizedBox.shrink(),
              data: (profile) {
                final statusDisplay =
                    _getStatusDisplay(profile.relationshipStatus);
                final count = profile.followerCount;
                return Column(
                  children: [
                    // No avatar, no name — just status and follower count.
                    Text(
                      statusDisplay,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    Gap(Spacing.sm.h),
                    Text(
                      '$count follower${count != 1 ? 's' : ''}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    Gap(Spacing.md.h),
                    if (!profile.isMine)
                      AppButton(
                        label: profile.isFollowing ? 'Unfollow' : 'Follow',
                        onPressed: () async {
                          if (profile.isFollowing) {
                            await ref.read(
                                unfollowUserProvider(widget.authorHandle)
                                    .future);
                          } else {
                            await ref.read(
                                followUserProvider(widget.authorHandle).future);
                          }
                          ref.invalidate(
                              authorProfileProvider(widget.authorHandle));
                        },
                        size: ButtonSize.small,
                        customColor: profile.isFollowing
                            ? colorScheme.surfaceContainerHighest
                            : colorScheme.primary,
                        textColor: profile.isFollowing
                            ? colorScheme.onSurface
                            : colorScheme.onPrimary,
                      ),
                  ],
                );
              },
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
