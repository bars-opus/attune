// lib/features/quiz/presentation/screens/conflict_style_result_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/conflict_style_result.dart';
import '../widgets/spectrum_bar.dart';
import '../widgets/share_quiz_button.dart';

class ConflictStyleResultScreen extends ConsumerStatefulWidget {
  final ConflictStyleResult result;

  const ConflictStyleResultScreen({super.key, required this.result});

  @override
  ConsumerState<ConflictStyleResultScreen> createState() =>
      _ConflictStyleResultScreenState();
}

class _ConflictStyleResultScreenState
    extends ConsumerState<ConflictStyleResultScreen>
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
    final summary = widget.result.getSummary();
    final description = widget.result.getDescription();
    final sortedData = widget.result.spectrumData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your conflict snapshot'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed:
              () => Navigator.popUntil(context, (route) => route.isFirst),
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
                // Primary and secondary summary
                Container(
                  padding: EdgeInsets.all(Spacing.md.w),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.md.r,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              Text(
                                widget.result.isTied
                                    ? 'Top tendency'
                                    : 'Primary',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
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
                                widget.result.isTied
                                    ? 'Also tied'
                                    : 'Secondary',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
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
                      Gap(Spacing.md.h),
                      Text(
                        summary,
                        style: textTheme.bodyMedium,
                        textAlign: TextAlign.center,
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
                      color:
                          isPrimary
                              ? colorScheme.primary
                              : colorScheme.primary.withValues(alpha: 0.4),
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
                Text(description, style: textTheme.bodyMedium),
                Gap(Spacing.xl.h),
                // Limitation note
                Container(
                  padding: EdgeInsets.all(Spacing.md.w),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
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
                          'This reflects how you answered today. Conflict responses can change with context, power, safety, culture, and relationship dynamics.',
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Gap(Spacing.xl.h),
                // Actions
                ShareQuizButton(quizType: 'conflict', result: widget.result),
                Gap(Spacing.md.h),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Retake quiz',
                        onPressed:
                            () => context.pushReplacementNamed(
                              'conflictStyleQuiz',
                            ),
                        size: ButtonSize.medium,
                        customColor: colorScheme.surfaceContainerHighest,
                        textColor: colorScheme.onSurface,
                      ),
                    ),
                    Gap(Spacing.md.w),
                    Expanded(
                      child: AppButton(
                        label: 'Back to profile',
                        onPressed:
                            () => Navigator.popUntil(
                              context,
                              (route) => route.isFirst,
                            ),
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
