import 'package:attune/core/utils/exports/export_screens.dart';

class CheckinBanner extends StatelessWidget {
  const CheckinBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SemanticContainerWidget(
      title: 'Weekly check-in',
      content:
          'Pulse is strongest when both partners submit the weekly check-in. It takes about 60 seconds.',
      icon: Icons.schedule,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
      borderColor: colorScheme.primary,
      iconColor: colorScheme.primary,
      textTheme: textTheme,
      child: Padding(
        padding: EdgeInsets.only(top: Spacing.md.h),
        child: AppButton(
          label: 'Open check-in',
          onPressed: () {
            context.pushNamed('weeklyCheckin');
          },
        ),
      ),
    );
  }
}
