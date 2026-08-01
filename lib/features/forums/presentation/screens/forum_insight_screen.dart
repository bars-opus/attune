// lib/features/forums/presentation/screens/forum_insight_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/polls/data/models/poll_model.dart';
import 'package:attune/core/polls/presentation/providers/poll_providers.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/forums/data/models/forum_post_model.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/widgets/forum_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/error_state.dart';

/// A single forum topic's data, visualized rather than listed as text rows.
///
/// Two independent async sources feed this screen — topicDetailsProvider
/// (the topic's own denormalized counters: forPeople/againstPeople,
/// totalPosts, timestamps) and forumPostsProvider (the full flat post
/// timeline: side, createdAt, likeCount, replyToPostId for every post).
/// Before this rewrite, this screen only ever read the first — every chart
/// below that needs per-post data (activity over time, engagement by side,
/// thread shape) was previously undisplayable here because nothing on
/// screen looked past the topic's own counters. Nothing here required new
/// data collection: forumPostsProvider already carries everything, the same
/// way DebateRoomScreen._repliesByParent already derives reply counts from
/// this exact list.
///
/// What's deliberately NOT charted: nothing buckets by author. No author
/// identity — not even a stable pseudonym — ever reaches the client
/// (FORUM.md §3), so there is no "who's winning" or per-person breakdown
/// possible here, only aggregate side/time/engagement/thread shape.
class ForumInsightScreen extends ConsumerWidget {
  final String topicId;

  const ForumInsightScreen({super.key, required this.topicId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final topicAsync = ref.watch(topicDetailsProvider(topicId));
    final postsAsync = ref.watch(forumPostsProvider(topicId));
    final pollAsync = ref.watch(pollProvider(PollTarget.topic(topicId)));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Forum insights',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      body: topicAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorStateWidget.from(error),
        data: (topic) {
          if (topic == null) {
            return Center(
              child: EmptyStateWidget(
                title: 'Forum not found',
                icon: Icons.bar_chart,
                subtitle: 'This forum may have been removed or archived.',
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The topic itself, Hero'd in from wherever this screen was
                // opened — this IS the topic content, so a separate
                // quoted-text repeat of topic.content directly below it
                // would just say the same thing twice.
                Padding(
                  padding: EdgeInsets.all(Spacing.lg.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppDivider(),
                      _buildQuickFacts(context, topic),
                      Gap(Spacing.xl.h),
                      _SideSplitCard(topic: topic),
                      // Everything below needs the actual post timeline —
                      // no posts yet means nothing meaningful to chart, so
                      // these sections just don't render rather than
                      // showing empty/zeroed charts.
                      postsAsync.maybeWhen(
                        data: (posts) {
                          if (posts.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ActivityOverTimeCard(posts: posts),
                              _EngagementBySideCard(posts: posts),
                              _ThreadShapeCard(posts: posts),
                            ],
                          );
                        },
                        orElse: () => const SizedBox.shrink(),
                      ),
                      pollAsync.maybeWhen(
                        data: (poll) {
                          if (poll == null || !poll.hasVoted) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Gap(Spacing.lg.h),
                              _PollResultsCard(poll: poll),
                            ],
                          );
                        },
                        orElse: () => const SizedBox.shrink(),
                      ),
                      Gap(Spacing.xl.h),
                      // Disclaimer
                      Container(
                        padding: EdgeInsets.all(Spacing.md.w),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withOpacity(0.3),
                          borderRadius: BorderRadius.circular(
                            BorderRadiusTokens.md.r,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: colorScheme.primary,
                            ),
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickFacts(BuildContext context, TopicModel topic) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final daysOld = DateTime.now().difference(topic.createdAt).inDays;

    return Column(
      children: [
        _buildInsightRow(
          'Started',
          '${_formatDate(topic.createdAt)} · $daysOld d ago',
          Icons.calendar_today,
          colorScheme,
          textTheme,
        ),
        if (topic.lastPostAt != null)
          _buildInsightRow(
            'Last activity',
            _formatTimeAgo(topic.lastPostAt!),
            Icons.access_time,
            colorScheme,
            textTheme,
          ),
      ],
    );
  }

  Widget _buildInsightRow(
    String label,
    String value,
    IconData icon,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return InfoRowWidget(
      subtitle: label,
      title: value,
      icon: icon,
      iconSize: 18.h,
      onTap: () {},
      disableTrailing: true,
      showAvatar: false,
      showTrailingArrow: false,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
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

/// Shared card chrome for every chart section — a title, a subtitle
/// explaining what the chart means (these are decision-driving numbers, not
/// decoration, so each one earns a plain-language read), and the chart
/// itself.
class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget chart;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.chart,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return CardInkWell(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            Gap(Spacing.xs.h),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            Gap(Spacing.md.h),
            chart,
          ],
        ),
      ),
    );
  }
}

/// FOR vs AGAINST as a donut — forPeople/againstPeople (distinct people who
/// picked each side, from user_forum_sides), NOT forPosts/againstPosts,
/// which count posts and would double-count anyone who posted more than
/// once. This is the same distinction ForumCardSubDetails already draws.
class _SideSplitCard extends StatelessWidget {
  final TopicModel topic;

  const _SideSplitCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final forCount = topic.forPeople;
    final againstCount = topic.againstPeople;
    final total = forCount + againstCount;

    if (total == 0) {
      return _ChartCard(
        title: 'Who\'s on which side',
        subtitle: 'No one has joined a side yet.',
        chart: const SizedBox.shrink(),
      );
    }

    final forShare = forCount / total;
    final againstShare = againstCount / total;

    return _ChartCard(
      title: 'Who\'s on which side',
      subtitle:
          '$total ${total == 1 ? 'person has' : 'people have'} joined a side.',
      chart: Row(
        children: [
          SizedBox(
            width: 120.w,
            height: 120.w,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 32.r,
                sections: [
                  PieChartSectionData(
                    value: forCount.toDouble(),
                    color: colorScheme.primary,
                    showTitle: false,
                    radius: 20.r,
                  ),
                  PieChartSectionData(
                    value: againstCount.toDouble(),
                    color: colorScheme.against,
                    showTitle: false,
                    radius: 20.r,
                  ),
                ],
              ),
            ),
          ),
          Gap(Spacing.lg.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegendRow(
                  color: colorScheme.primary,
                  label: 'FOR',
                  value: '$forCount · ${(forShare * 100).toStringAsFixed(0)}%',
                  textTheme: textTheme,
                ),
                Gap(Spacing.sm.h),
                _LegendRow(
                  color: colorScheme.against,
                  label: 'AGAINST',
                  value:
                      '$againstCount · ${(againstShare * 100).toStringAsFixed(0)}%',
                  textTheme: textTheme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final TextTheme textTheme;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Gap(Spacing.sm.w),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        Gap(Spacing.xs.w),
        Text(
          value,
          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
        ),
      ],
    );
  }
}

/// Posts per day since the topic's first post — shows whether the debate is
/// heating up, steady, or has gone quiet. Bucketed client-side from
/// forumPostsProvider's createdAt timestamps; capped at the most recent 14
/// days so a months-old topic doesn't render an unreadably wide/sparse axis.
class _ActivityOverTimeCard extends StatelessWidget {
  final List<ForumPostModel> posts;

  const _ActivityOverTimeCard({required this.posts});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const dayCount = 14;
    final firstDay = today.subtract(const Duration(days: dayCount - 1));

    // Stacked by side (FOR then AGAINST) rather than one undifferentiated
    // total — shows not just how much happened each day but which side was
    // driving it, the same primary/against pairing the side-split and
    // engagement charts use.
    final forCounts = List<int>.filled(dayCount, 0);
    final againstCounts = List<int>.filled(dayCount, 0);
    for (final post in posts) {
      final postDay = DateTime(
        post.createdAt.year,
        post.createdAt.month,
        post.createdAt.day,
      );
      final index = postDay.difference(firstDay).inDays;
      if (index < 0 || index >= dayCount) continue;
      if (post.side == 'for') {
        forCounts[index]++;
      } else {
        againstCounts[index]++;
      }
    }

    final totals = [
      for (var i = 0; i < dayCount; i++) forCounts[i] + againstCounts[i],
    ];
    final maxCount = totals.fold<int>(0, (a, b) => a > b ? a : b);
    if (maxCount == 0) {
      // Every post in this topic is older than the 14-day window — nothing
      // recent to chart, and a bar chart of all-zero bars would just read
      // as broken rather than "no recent activity."
      return const SizedBox.shrink();
    }

    return _ChartCard(
      title: 'Activity, last 14 days',
      subtitle: 'How many posts landed each day, by side.',
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 140.h,
            child: BarChart(
              BarChartData(
                maxY: (maxCount + 1).toDouble(),
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22.h,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        // Every other day labeled — 14 labels crammed onto a
                        // narrow chart overlap into an unreadable smear.
                        if (index < 0 || index >= dayCount || index.isOdd) {
                          return const SizedBox.shrink();
                        }
                        final day = firstDay.add(Duration(days: index));
                        return Padding(
                          padding: EdgeInsets.only(top: Spacing.xs.h),
                          child: Text(
                            '${day.day}',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < dayCount; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: totals[i].toDouble(),
                          width: 10.w,
                          borderRadius: BorderRadius.circular(3),
                          rodStackItems: [
                            BarChartRodStackItem(
                              0,
                              forCounts[i].toDouble(),
                              colorScheme.primary,
                            ),
                            BarChartRodStackItem(
                              forCounts[i].toDouble(),
                              totals[i].toDouble(),
                              colorScheme.against,
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Gap(Spacing.sm.h),
          Row(
            children: [
              _LegendRow(
                color: colorScheme.primary,
                label: 'FOR',
                value: '${forCounts.fold<int>(0, (a, b) => a + b)}',
                textTheme: textTheme,
              ),
              Gap(Spacing.md.w),
              _LegendRow(
                color: colorScheme.against,
                label: 'AGAINST',
                value: '${againstCounts.fold<int>(0, (a, b) => a + b)}',
                textTheme: textTheme,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Total likes received by FOR posts vs AGAINST posts — a proxy for which
/// side's arguments are actually landing with readers, distinct from which
/// side simply has more people (that's _SideSplitCard).
class _EngagementBySideCard extends StatelessWidget {
  final List<ForumPostModel> posts;

  const _EngagementBySideCard({required this.posts});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    var forLikes = 0;
    var againstLikes = 0;
    for (final post in posts) {
      if (post.side == 'for') {
        forLikes += post.likeCount;
      } else {
        againstLikes += post.likeCount;
      }
    }

    if (forLikes == 0 && againstLikes == 0) {
      return _ChartCard(
        title: 'Engagement by side',
        subtitle: 'No likes yet on either side\'s posts.',
        chart: const SizedBox.shrink(),
      );
    }

    final maxLikes =
        (forLikes > againstLikes ? forLikes : againstLikes).toDouble();

    return _ChartCard(
      title: 'Engagement by side',
      subtitle: 'Total likes received by each side\'s posts.',
      chart: SizedBox(
        height: 120.h,
        child: BarChart(
          BarChartData(
            maxY: maxLikes * 1.2,
            alignment: BarChartAlignment.spaceEvenly,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              show: true,
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24.h,
                  getTitlesWidget: (value, meta) {
                    final label = value.toInt() == 0 ? 'FOR' : 'AGAINST';
                    return Padding(
                      padding: EdgeInsets.only(top: Spacing.xs.h),
                      child: Text(
                        label,
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color:
                              value.toInt() == 0
                                  ? colorScheme.primary
                                  : colorScheme.against,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              BarChartGroupData(
                x: 0,
                barRods: [
                  BarChartRodData(
                    toY: forLikes.toDouble(),
                    color: colorScheme.primary,
                    width: 40.w,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
                showingTooltipIndicators: const [0],
              ),
              BarChartGroupData(
                x: 1,
                barRods: [
                  BarChartRodData(
                    toY: againstLikes.toDouble(),
                    color: colorScheme.against,
                    width: 40.w,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
            ],
            barTouchData: BarTouchData(
              enabled: false,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => Colors.transparent,
                tooltipPadding: EdgeInsets.zero,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  return BarTooltipItem(
                    rod.toY.toInt().toString(),
                    textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ) ??
                        const TextStyle(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What fraction of posts are original contributions vs replies-to-others —
/// shows whether this is a real back-and-forth debate or parallel
/// monologues. Uses replyToPostId, the same field
/// DebateRoomScreen._repliesByParent groups by.
class _ThreadShapeCard extends StatelessWidget {
  final List<ForumPostModel> posts;

  const _ThreadShapeCard({required this.posts});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final replyCount = posts.where((p) => p.replyToPostId != null).length;
    final originalCount = posts.length - replyCount;
    final replyShare = replyCount / posts.length;

    return _ChartCard(
      title: 'Thread shape',
      subtitle:
          replyShare > 0.3
              ? 'A real back-and-forth — plenty of posts reply directly to others.'
              : 'Mostly original posts so far, not much direct back-and-forth.',
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
            child: SizedBox(
              height: 28.h,
              child: Row(
                children: [
                  if (originalCount > 0)
                    Expanded(
                      flex: originalCount,
                      child: Container(color: colorScheme.primary),
                    ),
                  if (replyCount > 0)
                    Expanded(
                      flex: replyCount,
                      child: Container(
                        color: colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Gap(Spacing.sm.h),
          Row(
            children: [
              _LegendRow(
                color: colorScheme.primary,
                label: 'Original',
                value: '$originalCount',
                textTheme: textTheme,
              ),
              Gap(Spacing.md.w),
              _LegendRow(
                color: colorScheme.onSurface.withOpacity(0.3),
                label: 'Replies',
                value: '$replyCount',
                textTheme: textTheme,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Poll results, when the topic has a poll AND the viewer has voted (the
/// same gate PollCard uses elsewhere — results are masked server-side until
/// then, so there is nothing real to chart before that).
class _PollResultsCard extends StatelessWidget {
  final PollModel poll;

  const _PollResultsCard({required this.poll});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = poll.totalVotes ?? 0;

    return _ChartCard(
      title: 'Poll results',
      subtitle:
          total == 0
              ? 'No votes yet.'
              : '$total ${total == 1 ? 'vote' : 'votes'} so far.',
      chart: Column(
        children: [
          for (final option in poll.options) ...[
            _PollOptionBar(
              option: option,
              share: option.shareOf(poll.totalVotes) ?? 0,
              isMine: option.id == poll.myOptionId,
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            if (option != poll.options.last) Gap(Spacing.sm.h),
          ],
        ],
      ),
    );
  }
}

class _PollOptionBar extends StatelessWidget {
  final PollOptionModel option;
  final double share;
  final bool isMine;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _PollOptionBar({
    required this.option,
    required this.share,
    required this.isMine,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Gap(Spacing.sm.w),
            Text(
              '${(share * 100).toStringAsFixed(0)}%',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Gap(Spacing.xs.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(BorderRadiusTokens.xs.r),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 8.h,
            backgroundColor: colorScheme.surfaceContainerHighest,
            color:
                isMine
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      ],
    );
  }
}
