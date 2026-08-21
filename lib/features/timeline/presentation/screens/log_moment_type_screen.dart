// lib/features/timeline/presentation/screens/log_moment_type_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';

class LogMomentTypeScreen extends StatelessWidget {
  const LogMomentTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: ListView(
          children: [
            // Text(
            //   'What kind of moment is this?',
            //   style: textTheme.headlineSmall,
            // ),
            SemanticContainerWidget(
              content: 'What kind of moment is this?',
              icon: Icons.auto_awesome_outlined,
              isSkeleton: true,
              title: 'Log a moment',
              backgroundColor: colorScheme.primary.withOpacity(0.1),
              borderColor: colorScheme.primary,
              iconColor: colorScheme.primary,
              textTheme: textTheme,
            ),
            Gap(Spacing.lg.h),
            // ListView(
            // shrinkWrap: true,
            // crossAxisCount: 2,
            // mainAxisSpacing: Spacing.md.h,
            // crossAxisSpacing: Spacing.md.w,
            // childAspectRatio: 1.2,
            // children: [
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
              //   ),
              // ],
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return CardInkWell(
      elevation: 0,
      color: color.withOpacity(.3),
      onTap: () {
        context.pushNamed(
          'logMomentDetails',
          extra: (eventType: type, editEventId: null, initialData: null),
        );
      },
      child: InfoRowWidget(
        title: label,
        subtitle: '',
        backgroundColor: colorScheme.background,
        iconColor: color,

        // titleFontColor: colorScheme.background,
        icon: icon,
        showAvatar: true,
        showDivider: false,
        showTrailingArrow: true,

        onTap: () {
          context.pushNamed(
            'logMomentDetails',
            extra: (eventType: type, editEventId: null, initialData: null),
          );
        },
      ),
    );
  }
}
