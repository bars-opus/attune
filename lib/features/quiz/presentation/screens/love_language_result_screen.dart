// lib/features/quiz/presentation/screens/love_language_result_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/presentation/widgets/share_quiz_button.dart';
import 'package:attune/features/quiz/presentation/widgets/spectrum_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class LoveLanguageResultScreen extends ConsumerStatefulWidget {
  final LoveLanguageResult result;

  const LoveLanguageResultScreen({super.key, required this.result});

  @override
  ConsumerState<LoveLanguageResultScreen> createState() => _LoveLanguageResultScreenState();
}

class _LoveLanguageResultScreenState extends ConsumerState<LoveLanguageResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _revealController;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _revealController.forward();
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final primaryDisplay = widget.result.getPrimaryDisplay();
    final secondaryDisplay = widget.result.getSecondaryDisplay();
    final sortedData = widget.result.spectrumData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your love languages'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: SingleChildScrollView(
          child: FadeTransition(
            opacity: _revealController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Primary and secondary
                Container(
                  padding: EdgeInsets.all(Spacing.md.w),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              Text(
                                'Primary',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                              Gap(Spacing.xs.h),
                              Text(
                                primaryDisplay,
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          Gap(Spacing.xl.w),
                          Column(
                            children: [
                              Text(
                                'Secondary',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                              Gap(Spacing.xs.h),
                              Text(
                                secondaryDisplay,
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Gap(Spacing.xl.h),
                // Spectrum bars
                Text(
                  'Your spectrum',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Gap(Spacing.md.h),
                ...sortedData.map((item) {
                  final isPrimary = item['key'] == widget.result.primary;
                  return Padding(
                    padding: EdgeInsets.only(bottom: Spacing.sm.h),
                    child: SpectrumBar(
                      label: item['label'],
                      percentage: item['value'],
                      color: isPrimary ? colorScheme.primary : colorScheme.primary.withOpacity(0.5),
                      animation: _revealController,
                    ),
                  );
                }),
                Gap(Spacing.xl.h),
                // Description
                Text(
                  'What this means',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Gap(Spacing.md.h),
                Text(
                  widget.result.getDescription(widget.result.primary),
                  style: textTheme.bodyMedium,
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
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      Gap(Spacing.sm.w),
                      Expanded(
                        child: Text(
                          'This is a snapshot, not a label.',
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Gap(Spacing.xl.h),
                // Actions
                ShareQuizButton(
                  quizType: 'love_language',
                  result: widget.result,
                ),
                Gap(Spacing.md.h),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Retake quiz',
                        onPressed: () {
                          Navigator.popUntil(context, (route) => route.isFirst);
                        },
                        size: ButtonSize.medium,
                        customColor: colorScheme.surfaceContainerHighest,
                        textColor: colorScheme.onSurface,
                      ),
                    ),
                    Gap(Spacing.md.w),
                    Expanded(
                      child: AppButton(
                        label: 'Back to profile',
                        onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                        size: ButtonSize.medium,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
