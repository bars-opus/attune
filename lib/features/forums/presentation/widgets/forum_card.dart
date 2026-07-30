// lib/features/forums/presentation/widgets/forum_card.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relative_time.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/screens/debate_room_screen.dart';
import 'package:attune/core/widgets/tag_chip_row.dart';
import 'package:attune/features/forums/presentation/screens/side_selection_screen.dart';
import 'package:attune/features/forums/presentation/widgets/forum_card_subdetails.dart';
import 'package:attune/features/forums/presentation/widgets/mini_container_indicator.dart';
import 'package:attune/features/opinions/presentation/screen/tag_browse_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ForumCard extends ConsumerWidget {
  final TopicModel forum;
  final String? userSide;
  final bool isQuiet;

  /// True when this card is already showing inside the debate room it would
  /// otherwise navigate to (DebateRoomScreen pins the topic's own ForumCard
  /// at the top of its post list, the same way CommentThreadScreen pins an
  /// OpinionCard above its comments). Tapping a card that's already on the
  /// screen it navigates to would just re-push the same route, so this
  /// no-ops onTap instead of adding a second copy of the card's layout.
  final bool disableNavigation;

  const ForumCard({
    super.key,
    required this.forum,
    this.userSide,
    this.isQuiet = false,
    this.disableNavigation = false,
  });

  /// Hero'd between wherever this card is tapped from and
  /// ForumInsightScreen — same pattern as OpinionCard._heroTag, reused as
  /// the pinned header there instead of ForumInsightScreen repeating the
  /// topic content as its own separate Text.
  String get _heroTag => 'forum-${forum.id}';

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
            ? formatTimeAgo(forum.lastPostAt!)
            : formatTimeAgo(forum.createdAt);

    // Hero'd between the feed/list card and ForumInsightScreen — the topic
    // card itself transitions, same as OpinionCard between the feed and
    // CommentThreadScreen. Material(transparency) keeps InkWell's own
    // splash/highlight painting correctly during the flight, same reason
    // OpinionCard wraps its Hero child in one.
    return Hero(
      tag: _heroTag,
      child: Material(
        type: MaterialType.transparency,
        child: _buildCard(
          context,
          ref,
          colorScheme,
          textTheme,
          timeAgo,
          isAuthenticated,
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    TextTheme textTheme,
    String timeAgo,
    bool isAuthenticated,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      onTap:
          disableNavigation
              ? null
              : () {
                if (forum.status == 'archived') {
                  // Show read-only view
                  context.showInfoSnackbar(
                    'This forum is archived and read-only.',
                  );
                } else if (!isAuthenticated) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => DebateRoomScreen(
                            topicId: forum.id,
                            topicTitle: forum.content,
                            userSide: 'browse',
                            initialTopic: forum,
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
                            initialTopic: forum,
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
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.normal,
                color: colorScheme.onBackground,
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
            Gap(Spacing.md.h),

            Row(
              children: [
                Expanded(
                  child: ForumCardSubDetails(
                    forPeople: forum.forPeople.toString(),
                    againstPeople: forum.againstPeople.toString(),
                    contributors:
                        '${forum.totalPosts > 0 ? (forum.totalPosts / 2).ceil() : 0}',
                    userSide: userSide,
                  ),
                ),
                Gap(Spacing.md.w),
                Text(
                  timeAgo,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
            Gap(Spacing.md.h),

            // Bottom row: user side indicator + time + status
            Row(
              children: [
                // if (userSide != null)
                //   _buildStatChip(
                //     userSide == 'Browsing'
                //         ? 'Browsing'
                //         : 'Your side: $userSide',
                //     userSide == 'FOR'
                //         ? colorScheme.primary
                //         : userSide == 'AGAINST'
                //         ? colorScheme.error
                //         : colorScheme.surfaceContainerHighest,
                //   ),

                // Container(
                //   padding: EdgeInsets.symmetric(
                //     horizontal: Spacing.sm.w,
                //     vertical: Spacing.xs.h,
                //   ),
                //   decoration: BoxDecoration(
                //     color:
                //         userSide == 'FOR'
                //             ? colorScheme.primary.withOpacity(0.1)
                //             : userSide == 'AGAINST'
                //             ? colorScheme.error.withOpacity(0.1)
                //             : colorScheme.surfaceContainerHighest,
                //     borderRadius: BorderRadius.circular(
                //       BorderRadiusTokens.sm.r,
                //     ),
                //   ),
                //   child: Text(
                //     userSide == 'Browsing'
                //         ? 'Browsing'
                //         : 'Your side: $userSide',
                //     style: TextStyle(
                //       fontSize: 11,
                //       fontWeight: FontWeight.w500,
                //       color:
                //           userSide == 'FOR'
                //               ? colorScheme.primary
                //               : userSide == 'AGAINST'
                //               ? colorScheme.error
                //               : colorScheme.onSurface.withOpacity(0.6),
                //     ),
                //   ),
                // ),
                // if (userSide != null) Gap(Spacing.sm.w),
                if (isQuiet)
                  _buildStatChip('Quiet', colorScheme.surfaceContainerHighest),

                // Container(
                //   padding: EdgeInsets.symmetric(
                //     horizontal: Spacing.sm.w,
                //     vertical: Spacing.xs.h,
                //   ),
                //   decoration: BoxDecoration(
                //     color: colorScheme.surfaceContainerHighest,
                //     borderRadius: BorderRadius.circular(
                //       BorderRadiusTokens.sm.r,
                //     ),
                //   ),
                //   child: Text(
                //     'Quiet',
                //     style: TextStyle(
                //       fontSize: 10,
                //       color: colorScheme.onSurface.withOpacity(0.6),
                //     ),
                //   ),
                // ),
                if (forum.status == 'archived')
                  _buildStatChip(
                    'Archived',
                    colorScheme.surfaceContainerHighest,
                  ),

                // Container(
                //   padding: EdgeInsets.symmetric(
                //     horizontal: Spacing.sm.w,
                //     vertical: Spacing.xs.h,
                //   ),
                //   decoration: BoxDecoration(
                //     color: colorScheme.surfaceContainerHighest,
                //     borderRadius: BorderRadius.circular(
                //       BorderRadiusTokens.sm.r,
                //     ),
                //   ),
                //   child: Text(
                //     'Archived',
                //     style: TextStyle(
                //       fontSize: 10,
                //       color: colorScheme.onSurface.withOpacity(0.6),
                //     ),
                //   ),
                // ),
                if (forum.status == 'active' && !isQuiet)
                  _buildStatChip(
                    'Active',
                    colorScheme.primary.withOpacity(0.1),
                  ),

                // Container(
                //   padding: EdgeInsets.symmetric(
                //     horizontal: Spacing.sm.w,
                //     vertical: Spacing.xs.h,
                //   ),
                //   decoration: BoxDecoration(
                //     color: colorScheme.primary.withOpacity(0.1),
                //     borderRadius: BorderRadius.circular(
                //       BorderRadiusTokens.sm.r,
                //     ),
                //   ),
                //   child: Text(
                //     'Active',
                //     style: TextStyle(
                //       fontSize: 10,
                //       fontWeight: FontWeight.w500,
                //       color: colorScheme.primary,
                //     ),
                //   ),
                // ),
              ],
            ),
            Gap(Spacing.sm.h),
            AppDivider(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, Color color) {
    return MiniContainerIndicator(color: color, text: label);
  }
}
