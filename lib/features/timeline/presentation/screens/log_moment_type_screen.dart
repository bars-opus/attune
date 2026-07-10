// lib/features/timeline/presentation/screens/log_moment_type_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'log_moment_details_screen.dart';

class LogMomentTypeScreen extends StatelessWidget {
  const LogMomentTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log a moment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What kind of moment is this?',
              style: textTheme.headlineSmall,
            ),
            Gap(Spacing.lg.h),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              mainAxisSpacing: Spacing.md.h,
              crossAxisSpacing: Spacing.md.w,
              childAspectRatio: 1.2,
              children: [
                _buildTypeCard(
                  context,
                  type: 'milestone',
                  icon: Icons.emoji_events_outlined,
                  label: 'Milestone',
                  color: Theme.of(context).colorScheme.primary,
                ),
                _buildTypeCard(
                  context,
                  type: 'highlight',
                  icon: Icons.favorite_outline,
                  label: 'Highlight',
                  color: Colors.amber,
                ),
                _buildTypeCard(
                  context,
                  type: 'conflict',
                  icon: Icons.flash_on_outlined,
                  label: 'Conflict',
                  color: Colors.red,
                ),
                _buildTypeCard(
                  context,
                  type: 'first',
                  icon: Icons.star_outline,
                  label: 'First',
                  color: Colors.purple,
                ),
                _buildTypeCard(
                  context,
                  type: 'anniversary',
                  icon: Icons.cake_outlined,
                  label: 'Anniversary',
                  color: Colors.pink,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard(
    BuildContext context, {
    required String type,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LogMomentDetailsScreen(eventType: type),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: BorderWidthTokens.hairline,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            Gap(Spacing.sm.h),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
