import 'package:attune/core/utils/exports/export_screens.dart';

class CheckinCompleteScreen extends StatelessWidget {
  const CheckinCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Check-in complete')),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Spacing.lg.w),
          child: Center(
            child: SemanticContainerWidget(
              title: 'Check-in saved',
              content:
                  'Your weekly reflection has been recorded. Shared pulse tools stay relationship-aware and update as more data arrives.',
              icon: Icons.favorite,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              borderColor: colorScheme.primary,
              iconColor: colorScheme.primary,
              textTheme: textTheme,
              child: Padding(
                padding: EdgeInsets.only(top: Spacing.md.h),
                child: AppButton(
                  label: 'Back to chat',
                  onPressed: () => context.go(RouteNames.home),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
