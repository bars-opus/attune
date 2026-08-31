// Session History Card Widget
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';

class SessionHistoryCard extends StatelessWidget {
  final ThisOrThatSession session;
  final VoidCallback onHide;
  final VoidCallback onTap;

  const SessionHistoryCard({
    super.key,
    required this.session,
    required this.onHide,
    required this.onTap,
  });

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

  String _getToneDisplay() {
    switch (session.tone) {
      case 'connecting':
        return 'Connecting';
      case 'romantic':
        return 'Romantic';
      case 'playful':
        return 'Playful';
      case 'spicy':
        return 'Spicy';
      case 'intimate':
        return 'Intimate';
      default:
        return session.tone;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final matchPercentage = session.matchPercentage;
    final showMatchText = matchPercentage >= 60;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: Spacing.md.w,
          vertical: Spacing.xs.h,
        ),
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Game icon and type
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
                  child: Row(
                    children: [
                      const Text('🔀', style: TextStyle(fontSize: 14)),
                      Gap(Spacing.xs.w),
                      Text(
                        'This or That',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Tone badge
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.sm.w,
                    vertical: Spacing.xs.h,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.sm.r,
                    ),
                  ),
                  child: Text(_getToneDisplay(), style: textTheme.labelSmall),
                ),
                Gap(Spacing.sm.w),
                // Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (value) {
                    if (value == 'hide') onHide();
                  },
                  itemBuilder:
                      (context) => const [
                        PopupMenuItem(
                          value: 'hide',
                          child: Text('Hide from my view'),
                        ),
                      ],
                ),
              ],
            ),
            Gap(Spacing.md.h),
            // Date
            Text(
              _formatDate(session.createdAt),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            Gap(Spacing.sm.h),
            // Match info
            Row(
              children: [
                Text(
                  '${session.matchCount}/${session.totalRoundsCompleted} matched',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (showMatchText)
                  Text(
                    '${matchPercentage.toStringAsFixed(0)}%',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (!showMatchText)
                  Text(
                    'Different picks',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            if (showMatchText) ...[
              Gap(Spacing.xs.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                child: LinearProgressIndicator(
                  value: matchPercentage / 100,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
