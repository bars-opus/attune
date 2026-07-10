import 'package:attune/core/utils/exports/export_screens.dart';

class OnboardingInfoTile extends StatelessWidget {
  const OnboardingInfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: Spacing.smMd.h),
      child: SemanticContainerWidget(
        content: subtitle,
        icon: icon,
        title: title,
        backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
        borderColor: colorScheme.primary,
        iconColor: colorScheme.primary,
        textTheme: Theme.of(context).textTheme,
      ),
    );
  }
}
