// lib/features/safety/presentation/screens/safety_resources_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/safety_providers.dart';

class SafetyResourcesScreen extends ConsumerWidget {
  static const routeName = '/safety-resources';

  const SafetyResourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support resources'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              // Quick exit
              ref.read(quickExitProvider).call(context);
            },
            tooltip: 'Quick exit',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Disclaimer
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Column(
                children: [
                  Text(
                    'If something does not feel safe, these contacts and planning resources may be useful.',
                    style: textTheme.bodyMedium,
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    'Attune cannot assess an emergency or contact help for you.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl.h),

            // Quick exit button
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.exit_to_app, size: 32),
                  Gap(Spacing.sm.h),
                  Text(
                    'Quick exit',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.error,
                    ),
                  ),
                  Gap(Spacing.xs.h),
                  Text(
                    'Tap to exit the app and show a neutral screen.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Gap(Spacing.md.h),
                  AppButton(
                    label: 'Exit now',
                    onPressed: () {
                      ref.read(quickExitProvider).call(context);
                    },
                    size: ButtonSize.medium,
                    customColor: colorScheme.error,
                    textColor: colorScheme.onPrimary,
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl.h),

            // Helplines
            Text(
              'Helplines',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            _buildHelplineCard(
              context,
              country: '🇬🇭 Ghana',
              service: 'Ghana Police DOVVSU',
              phone: '055 100 0900',
              website: 'https://police.gov.gh/',
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            Gap(Spacing.md.h),
            _buildHelplineCard(
              context,
              country: '🇺🇸 United States',
              service: 'National Domestic Violence Hotline',
              phone: '800-799-SAFE (7233)',
              website: 'https://www.thehotline.org/',
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            Gap(Spacing.md.h),
            _buildHelplineCard(
              context,
              country: '🇬🇧 United Kingdom',
              service: 'Refuge National Domestic Abuse Helpline',
              phone: '0808 2000 247',
              website: 'https://www.refuge.org.uk/',
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            Gap(Spacing.xl.h),

            // Safety tips
            Text(
              'Safety tips',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            _buildTip(
              'Trust your instincts — you know what feels safe and what doesn\'t.',
              colorScheme,
              textTheme,
            ),
            _buildTip(
              'Consider creating a safety plan for leaving quickly if needed.',
              colorScheme,
              textTheme,
            ),
            _buildTip(
              'Reach out to someone you trust — a friend, family member, or professional.',
              colorScheme,
              textTheme,
            ),
            _buildTip(
              'If you are in immediate danger, call your local emergency number.',
              colorScheme,
              textTheme,
            ),

            Gap(Spacing.xl.h),

            // Dismiss
            AppButton(
              label: 'Not relevant right now',
              onPressed: () => Navigator.pop(context),
              size: ButtonSize.medium,
              customColor: colorScheme.surfaceContainerHighest,
              textColor: colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelplineCard(
    BuildContext context, {
    required String country,
    required String service,
    required String phone,
    required String website,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            country,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          Gap(Spacing.xs.h),
          Text(
            service,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          Gap(Spacing.xs.h),
          Row(
            children: [
              const Icon(Icons.phone, size: 14),
              Gap(Spacing.xs.w),
              Text(phone, style: textTheme.bodySmall),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.language, size: 14),
              Gap(Spacing.xs.w),
              Text(
                website,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String text, ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: EdgeInsets.only(bottom: Spacing.sm.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(child: Text(text, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
