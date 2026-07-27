// lib/features/forums/presentation/widgets/forum_card.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/screens/debate_room_screen.dart';
import 'package:attune/core/widgets/tag_chip_row.dart';
import 'package:attune/features/forums/presentation/screens/side_selection_screen.dart';
import 'package:attune/features/opinions/presentation/screen/tag_browse_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ForumCard extends ConsumerWidget {
  final TopicModel forum;
  final String? userSide;
  final bool isQuiet;

  const ForumCard({
    super.key,
    required this.forum,
    this.userSide,
    this.isQuiet = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isAuthenticated =
        ref.watch(supabaseClientProvider).auth.currentUser?.id != null;

    final forPercentage =
        forum.totalPosts > 0
            ? (forum.forPosts / forum.totalPosts * 100).toStringAsFixed(0)
            : '0';
    final againstPercentage =
        forum.totalPosts > 0
            ? (forum.againstPosts / forum.totalPosts * 100).toStringAsFixed(0)
            : '0';

    final timeAgo =
        forum.lastPostAt != null
            ? _formatTimeAgo(forum.lastPostAt!)
            : _formatTimeAgo(forum.createdAt);

    return Card(
      margin: EdgeInsets.only(bottom: Spacing.md.h),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        onTap: () {
          if (forum.status == 'archived') {
            // Show read-only view
            context.showInfoSnackbar('This forum is archived and read-only.');
          } else if (!isAuthenticated) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => DebateRoomScreen(
                      topicId: forum.id,
                      topicTitle: forum.content,
                      userSide: 'browse',
                    ),
              ),
            );
          } else if (userSide != null && userSide != 'Browsing') {
            // User already has a side
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => DebateRoomScreen(
                      topicId: forum.id,
                      topicTitle: forum.content,
                      userSide: userSide!.toLowerCase(),
                    ),
              ),
            );
          } else {
            // User needs to pick a side
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SideSelectionScreen(topic: forum),
              ),
            );
          }
        },
        child: Padding(
          padding: EdgeInsets.all(Spacing.md.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Topic content
              Text(
                forum.content,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              // Directly under the topic text and above the stats row, same
              // placement as on an opinion card. Collapses to nothing when the
              // topic is untagged (most are), so no gap is reserved.
              TagChipRow(
                tags: forum.tags,
                onTagTap:
                    (slug) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TagBrowseScreen(tagSlug: slug),
                      ),
                    ),
              ),
              Gap(Spacing.sm.h),
              // Stats row
              Row(
                children: [
                  // FOR count
                  _buildStatChip('FOR ${forum.forPosts}', colorScheme.primary),
                  Gap(Spacing.sm.w),
                  // AGAINST count
                  _buildStatChip(
                    'AGAINST ${forum.againstPosts}',
                    colorScheme.error,
                  ),
                  const Spacer(),
                  // Total participants
                  Text(
                    '${forum.totalPosts > 0 ? (forum.totalPosts / 2).ceil() : 0} contributors',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
              Gap(Spacing.sm.h),
              // Bottom row: user side indicator + time + status
              Row(
                children: [
                  if (userSide != null)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: Spacing.sm.w,
                        vertical: Spacing.xs.h,
                      ),
                      decoration: BoxDecoration(
                        color:
                            userSide == 'FOR'
                                ? colorScheme.primary.withOpacity(0.1)
                                : userSide == 'AGAINST'
                                ? colorScheme.error.withOpacity(0.1)
                                : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.sm.r,
                        ),
                      ),
                      child: Text(
                        userSide == 'Browsing'
                            ? 'Browsing'
                            : 'Your side: $userSide',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color:
                              userSide == 'FOR'
                                  ? colorScheme.primary
                                  : userSide == 'AGAINST'
                                  ? colorScheme.error
                                  : colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  if (userSide != null) Gap(Spacing.sm.w),
                  Text(
                    timeAgo,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const Spacer(),
                  if (isQuiet)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: Spacing.sm.w,
                        vertical: Spacing.xs.h,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.sm.r,
                        ),
                      ),
                      child: Text(
                        'Quiet',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  if (forum.status == 'archived')
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: Spacing.sm.w,
                        vertical: Spacing.xs.h,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.sm.r,
                        ),
                      ),
                      child: Text(
                        'Archived',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  if (forum.status == 'active' && !isQuiet)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: Spacing.sm.w,
                        vertical: Spacing.xs.h,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.sm.r,
                        ),
                      ),
                      child: Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.sm.w,
        vertical: Spacing.xs.h,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
