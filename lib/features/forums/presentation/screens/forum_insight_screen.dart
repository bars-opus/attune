// lib/features/forums/presentation/screens/forum_insight_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/error_state.dart';



class ForumInsightScreen extends ConsumerWidget {
  final String topicId;

  const ForumInsightScreen({super.key, required this.topicId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final topicAsync = ref.watch(topicDetailsProvider(topicId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forum insights', style: TextStyle(fontSize: 18)),
      ),
      body: topicAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorStateWidget.from(error),
        data: (topic) {
          // Handle null topic
          if (topic == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                  Gap(Spacing.md.h),
                  Text(
                    'Forum not found',
                    style: textTheme.titleMedium,
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    'This forum may have been removed or archived.',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          final daysOld = DateTime.now().difference(topic.createdAt).inDays;
          final totalPosts = topic.totalPosts;
          final forPercentage = totalPosts > 0
              ? (topic.forPosts / totalPosts * 100).toStringAsFixed(0)
              : '0';
          final againstPercentage = totalPosts > 0
              ? (topic.againstPosts / totalPosts * 100).toStringAsFixed(0)
              : '0';

          return SingleChildScrollView(
            padding: EdgeInsets.all(Spacing.lg.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Topic title
                Text(
                  '"${topic.content}"',
                  style: textTheme.headlineSmall,
                ),
                Gap(Spacing.lg.h),
                // Started info
                _buildInsightRow(
                  'Started',
                  '${_formatDate(topic.createdAt)} · $daysOld days ago',
                  Icons.calendar_today,
                  colorScheme,
                  textTheme,
                ),
                Gap(Spacing.md.h),
                // Contributors (estimated)
                _buildInsightRow(
                  'Contributors',
                  '${totalPosts > 0 ? (totalPosts / 2).ceil() : 0} total · '
                  '${topic.forPosts} FOR · ${topic.againstPosts} AGAINST',
                  Icons.people_outline,
                  colorScheme,
                  textTheme,
                ),
                Gap(Spacing.md.h),
                // Total posts
                _buildInsightRow(
                  'Total posts',
                  '$totalPosts posts · $forPercentage% FOR · $againstPercentage% AGAINST',
                  Icons.chat_bubble_outline,
                  colorScheme,
                  textTheme,
                ),
                Gap(Spacing.md.h),
                // Last activity
                if (topic.lastPostAt != null)
                  _buildInsightRow(
                    'Last activity',
                    _formatTimeAgo(topic.lastPostAt!),
                    Icons.access_time,
                    colorScheme,
                    textTheme,
                  ),
                Gap(Spacing.xl.h),
                // Disclaimer
                Container(
                  padding: EdgeInsets.all(Spacing.md.w),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
                      Gap(Spacing.sm.w),
                      Expanded(
                        child: Text(
                          'No winner is declared. This is a living debate.',
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInsightRow(
    String label,
    String value,
    IconData icon,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        Gap(Spacing.md.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Gap(Spacing.xs.h),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  String _getMonth(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays > 0) return '${diff.inDays} days ago';
    if (diff.inHours > 0) return '${diff.inHours} hours ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes} minutes ago';
    return 'just now';
  }
}
