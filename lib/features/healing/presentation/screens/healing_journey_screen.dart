// lib/features/healing/presentation/screens/healing_journey_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HealingJourneyScreen extends ConsumerWidget {
  const HealingJourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final journeyAsync = ref.watch(healingJourneyProvider);
    final startContextAsync = ref.watch(healingStartContextProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Healing journey',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        centerTitle: true,
      ),
      body: journeyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stack) => Center(
              child: ErrorStateWidget(subtitle: 'Error: $error', title: ''),
            ),
        data: (journey) {
          if (journey == null) {
            return _buildEmptyState(context, ref, startContextAsync);
          }

          final stages = _getStageStatus(journey);
          final currentStage = journey.currentStage;

          return Padding(
            padding: EdgeInsets.all(Spacing.lg.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress overview
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
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List.generate(5, (index) {
                          final stage = index + 1;
                          final isComplete = stages[stage] == 'complete';
                          final isCurrent =
                              stage == currentStage && !isComplete;
                          return Column(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      isComplete
                                          ? colorScheme.primary
                                          : isCurrent
                                          ? colorScheme.primary.withValues(
                                            alpha: 0.2,
                                          )
                                          : colorScheme.surfaceContainerHighest,
                                  border: Border.all(
                                    color:
                                        isCurrent
                                            ? colorScheme.primary
                                            : colorScheme.outline.withValues(
                                              alpha: 0.2,
                                            ),
                                    width: isCurrent ? 2 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    isComplete ? '✓' : '$stage',
                                    style: TextStyle(
                                      color:
                                          isComplete
                                              ? colorScheme.onPrimary
                                              : isCurrent
                                              ? colorScheme.primary
                                              : colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                              ),
                              Gap(Spacing.xs.h),
                              Text(
                                _getStageLabel(stage),
                                style: textTheme.labelSmall?.copyWith(
                                  color:
                                      isComplete
                                          ? colorScheme.primary
                                          : colorScheme.onSurface.withValues(
                                            alpha: 0.5,
                                          ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                      Gap(Spacing.md.h),
                      Text(
                        journey.isFullyComplete
                            ? '✨ Journey complete'
                            : 'Stage ${journey.currentStage} of 5',
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Gap(Spacing.xl.h),

                // Stage description and action
                Text(
                  _getStageTitle(journey.currentStage),
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Gap(Spacing.md.h),
                Text(
                  _getStageDescription(journey.currentStage),
                  style: textTheme.bodyMedium,
                ),
                const Spacer(),

                if (journey.isFullyComplete) ...[
                  if (journey.isEligibleForDating)
                    Container(
                      padding: EdgeInsets.all(Spacing.md.w),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.md.r,
                        ),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'You can choose whether to explore Dating Mode when it becomes available.',
                            style: textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          Gap(Spacing.md.h),
                          Text(
                            'Dating Mode is coming soon.',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Gap(Spacing.md.h),
                  AppButton(
                    label: 'Retake readiness check-in',
                    onPressed: () {
                      // Navigate to readiness quiz
                    },
                    size: ButtonSize.medium,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ] else ...[
                  AppButton(
                    label: 'Continue →',
                    onPressed: () {
                      context.pushNamed(
                        'healingStage',
                        extra: (journey: journey, stage: journey.currentStage),
                      );
                    },
                    size: ButtonSize.large,
                    width: double.infinity,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<HealingStartContext?> startContextAsync,
  ) {
    return Center(
      child: startContextAsync.when(
        loading: () => const CircularProgressIndicator(),
        error: (_, __) => const SizedBox.shrink(),
        data: (startContext) {
          return EmptyStateWidget(
            icon: Icons.healing_outlined,
            title:
                'When you\'re ready, a healing journey is available. This private journey is here for you when you need it.',
            subtitle:
                'Healing Mode becomes available after an ended relationship or a previously saved journey.',
            actionLabel: startContext == null ? '' : 'Start journey',
            onAction:
                startContext == null
                    ? () {}
                    : () async {
                      await ref.read(
                        startHealingJourneyProvider(startContext!).future,
                      );
                      ref.invalidate(healingJourneyProvider);
                    },
          );
        },
      ),
    );
  }

  Map<int, String> _getStageStatus(HealingJourney journey) {
    return {
      1: journey.isReflectionComplete ? 'complete' : 'pending',
      2: journey.isPostMortemComplete ? 'complete' : 'pending',
      3: journey.isPatternAwarenessComplete ? 'complete' : 'pending',
      4: journey.isPortraitComplete ? 'complete' : 'pending',
      5: journey.isReadinessComplete ? 'complete' : 'pending',
    };
  }

  String _getStageLabel(int stage) {
    switch (stage) {
      case 1:
        return 'Reflect';
      case 2:
        return 'Post-mortem';
      case 3:
        return 'Patterns';
      case 4:
        return 'Portrait';
      case 5:
        return 'Readiness';
      default:
        return '';
    }
  }

  String _getStageTitle(int stage) {
    switch (stage) {
      case 1:
        return 'Reflection';
      case 2:
        return 'Relationship reflection';
      case 3:
        return 'Pattern awareness';
      case 4:
        return 'Your personal pattern portrait';
      case 5:
        return 'Readiness check-in';
      default:
        return '';
    }
  }

  String _getStageDescription(int stage) {
    switch (stage) {
      case 1:
        return 'Take a moment to reflect on what you learned from this relationship.';
      case 2:
        return 'A grounded, non-blaming observation about patterns that were present.';
      case 3:
        return 'Your quiz dimensions and relationship tendencies, with clear source labels.';
      case 4:
        return 'A warm synthesis of how you show up in relationships.';
      case 5:
        return 'Seven self-reflection questions to check in with yourself.';
      default:
        return '';
    }
  }
}
