// lib/features/healing/presentation/screens/healing_journey_screen.dart

import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';
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
    final docs = HealingDocs();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Healing journey',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        centerTitle: true,
        actions: [
          AppIconButton(
            icon: Icons.notes_rounded,
            tooltip: 'Docs',
            onPressed: () {
              BottomSheetUtils.showDocumentationBottomSheet(
                context: context,
                showButtons: false,
                widget: DocumentationTabView(
                  module: docs,
                  showDocumentationFirst: true,
                ),
              );
            },
          ),
        ],
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
                Text(
                  journey.isFullyComplete
                      ? '✨ Journey complete'
                      : 'Stage ${journey.currentStage} of 5',
                  style: textTheme.bodyMedium,
                ),
                Gap(Spacing.sm.h),
                CardInkWell(
                  borderRadius: BorderRadiusTokens.floatingNavAll,
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
                              AnimatedScaleFade(
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeOutBack,

                                child: Container(
                                  width: isCurrent ? 50.w : 45.2,
                                  height: isCurrent ? 50.h : 45.h,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        isComplete
                                            ? colorScheme.primary
                                            : isCurrent
                                            ? colorScheme.primary
                                            : Colors.grey.withOpacity(.1),
                                  ),
                                  child: Center(
                                    child: Text(
                                      isComplete ? '✓' : '$stage',
                                      style: textTheme.titleLarge?.copyWith(
                                        fontWeight:
                                            isCurrent
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                        color:
                                            isComplete
                                                ? colorScheme.onPrimary
                                                : isCurrent
                                                ? colorScheme.background
                                                    .withOpacity(.8)
                                                : colorScheme.onSurface
                                                    .withValues(alpha: 0.5),
                                        fontSize:
                                            isCurrent
                                                ? FontSizeTokens.xxl
                                                : FontSizeTokens.xl,
                                      ),
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
                    ],
                  ),
                ),

                Gap(Spacing.xl.h),

                // Stage description and action
                Text(
                  _getStageTitle(journey.currentStage),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    fontSize: FontSizeTokens.xxl.sp,
                  ),
                ),
                // Gap(Spacing.md.h),
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
                  _RetakeReadinessButton(journey: journey),
                ] else ...[
                  AppButton(
                    elevation: 0,
                    label: 'Continue →',
                    onPressed: () {
                      context.pushNamed(
                        'healingStage',
                        extra: (journey: journey, stage: journey.currentStage),
                      );
                    },
                    textColor: colorScheme.surface,
                    size: ButtonSize.small,
                    width: double.infinity,
                    padding: Spacing.horizontalMd,
                    height: 40.h,
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

/// Retake action for a finished journey. Kept as its own widget so the cooldown
/// lookup does not put the whole dashboard back into a loading state.
class _RetakeReadinessButton extends ConsumerWidget {
  const _RetakeReadinessButton({required this.journey});

  final HealingJourney journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final attemptAsync = ref.watch(latestReadinessAttemptProvider(journey.id));

    final submittedAtRaw = attemptAsync.valueOrNull?['submitted_at'] as String?;
    final lastAttemptAt =
        submittedAtRaw == null ? null : DateTime.tryParse(submittedAtRaw);

    // Until the attempt resolves we cannot know the cooldown, so hold the
    // action rather than let a tap through and be bounced back.
    final isResolving = attemptAsync.isLoading;
    final remaining = journey.retakeAvailableIn(lastAttemptAt);
    final canRetake = !isResolving && remaining == Duration.zero;

    // Round up so a wait of 6d 2h reads "7 days", never "6 days" when the user
    // would still be blocked tomorrow.
    final daysRemaining = (remaining.inHours / 24).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          elevation: 0,
          label: 'Retake readiness check-in',
          onPressed:
              canRetake
                  ? () {
                    context.pushNamed(
                      'healingStage',
                      extra: (journey: journey, stage: 5),
                    );
                  }
                  : null,
          textColor: colorScheme.surface,
          size: ButtonSize.small,
          isDisabled: !canRetake,
          width: double.infinity,
          padding: Spacing.horizontalMd,
          height: 40.h,
        ),

        if (!canRetake && !isResolving) ...[
          Gap(Spacing.sm.h),
          Text(
            daysRemaining == 1
                ? 'You can retake this in 1 day.'
                : 'You can retake this in $daysRemaining days.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
