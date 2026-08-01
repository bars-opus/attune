import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/data/models/dating_introduction.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingDashboardScreen extends ConsumerWidget {
  const DatingDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(datingModeEnabledProvider);
    final enrollmentAsync = ref.watch(datingEnrollmentProvider);
    final eligibilityAsync = ref.watch(datingEligibilityProvider);

    return enabledAsync.when(
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => _buildUnavailableScaffold(),
      data: (enabled) {
        if (!enabled) return _buildUnavailableScaffold();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Dating Mode'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Quick exit',
                onPressed: () => QuickExitService.execute(context),
              ),
              IconButton(
                icon: const Icon(Icons.favorite_outline),
                tooltip: 'Matches',
                onPressed: () {
                  context.pushNamed('datingMatches');
                },
              ),
              IconButton(
                icon: const Icon(Icons.shield_outlined),
                tooltip: 'Safety resources',
                onPressed: () {
                  context.pushNamed('safetyResources');
                },
              ),
            ],
          ),
          body: enrollmentAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, stack) => const Center(
                  child: Text(
                    'Dating Mode is unavailable right now. Please try again.',
                  ),
                ),
            data: (enrollment) {
              if (enrollment == null) {
                return eligibilityAsync.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, stack) => const Center(
                        child: Text(
                          'Eligibility could not be checked right now.',
                        ),
                      ),
                  data:
                      (eligibility) =>
                          _buildPreEnrollmentState(context, ref, eligibility),
                );
              }

              switch (enrollment.state) {
                case 'eligible_to_opt_in':
                  return _buildEligibleState(context);
                case 'profile_draft':
                  return _buildProfileDraftState(context);
                case 'active':
                  return _buildActiveState(context, ref);
                case 'paused':
                  return _buildPausedState(context, ref);
                case 'exited':
                  return _buildExitedState(context);
                case 'suspended':
                  return _buildSuspendedState(context);
                default:
                  return _buildPreEnrollmentState(
                    context,
                    ref,
                    const <String, dynamic>{'is_eligible': false},
                  );
              }
            },
          ),
        );
      },
    );
  }

  Scaffold _buildUnavailableScaffold() => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Dating Mode is not available yet.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );

  Widget _buildPreEnrollmentState(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> eligibility,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final isEligible = eligibility['is_eligible'] == true;
    final reason =
        eligibility['message'] as String? ??
        'Dating Mode unlocks only after the Healing eligibility transition and a separate opt-in.';

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isEligible ? Icons.favorite_outline : Icons.hourglass_bottom,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            Gap(Spacing.md.h),
            Text(
              isEligible
                  ? 'You can opt in to Dating Mode'
                  : 'Dating Mode is not available yet',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),
            Text(
              reason,
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            if (isEligible)
              AppButton(
                label: 'Get started',
                onPressed: () {
                  context.pushNamed('datingConsent');
                },
                size: ButtonSize.large,
                width: double.infinity,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEligibleState(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            Gap(Spacing.md.h),
            Text(
              'You are eligible to opt in',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),
            Text(
              'Dating Mode stays separate from Healing. You choose whether to enroll, activate a profile, or pause later.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            AppButton(
              label: 'Review consent',
              onPressed: () {
                context.pushNamed('datingConsent');
              },
              size: ButtonSize.large,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDraftState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.edit_outlined, size: 64),
            Gap(Spacing.md.h),
            Text(
              'Complete your dating profile',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Gap(Spacing.sm.h),
            Text(
              'Add your profile details and preferences before activation.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            AppButton(
              label: 'Open profile',
              onPressed: () {
                context.pushNamed('datingProfile');
              },
              size: ButtonSize.large,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveState(BuildContext context, WidgetRef ref) {
    final introductionsAsync = ref.watch(datingIntroductionsProvider);

    return introductionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, stack) => const Center(
            child: Text('Introductions are unavailable right now.'),
          ),
      data: (introductions) {
        if (introductions.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(Spacing.xl.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  Gap(Spacing.md.h),
                  Text(
                    'No new introductions right now',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    'Attune keeps this small and curated. Check back later rather than refreshing for volume.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(Spacing.md.w),
          itemCount: introductions.length,
          itemBuilder: (context, index) {
            // Cards settle in with a short per-index stagger so the curated
            // list arrives warmly rather than snapping in. Reduce-motion safe
            // (SettleIn renders at rest). Never a countdown/urgency cue (M8).
            return SettleIn(
              key: ValueKey('intro_${introductions[index].id}'),
              duration:
                  const Duration(milliseconds: 260) +
                  Duration(milliseconds: 60 * index),
              child: _buildIntroductionCard(context, ref, introductions[index]),
            );
          },
        );
      },
    );
  }

  Widget _buildIntroductionCard(
    BuildContext context,
    WidgetRef ref,
    DatingIntroduction introduction,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final explanationText = introduction.explanationFeatures.values
        .whereType<Map>()
        .map((value) => value['description'] as String?)
        .whereType<String>()
        .firstWhere(
          (_) => true,
          orElse:
              () =>
                  'Shared signals are still limited, so this preview stays modest.',
        );

    return Container(
      margin: EdgeInsets.only(bottom: Spacing.md.h),
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The strongest band breathes a gentle glow so the signal isn't
          // carried by color alone (accessibility, L1). Weaker bands stay
          // static. This is a warmth cue, never urgency (M8).
          GlowPulse(
            active: introduction.displayBand == 'promising_shared_ground',
            color: introduction.bandColor,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.sm.w,
                vertical: Spacing.xs.h,
              ),
              decoration: BoxDecoration(
                color: introduction.bandColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
              child: Text(
                'Alignment preview: ${introduction.bandLabel}',
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: introduction.bandColor,
                ),
              ),
            ),
          ),
          Gap(Spacing.md.h),
          Text(introduction.displayName, style: textTheme.titleMedium),
          if (introduction.cityRegionCode != null ||
              introduction.relationshipIntention != null) ...[
            Gap(Spacing.xs.h),
            Text(
              [
                introduction.cityRegionCode,
                introduction.relationshipIntention,
              ].whereType<String>().join(' • '),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
          if (introduction.summary != null &&
              introduction.summary!.isNotEmpty) ...[
            Gap(Spacing.sm.h),
            Text(introduction.summary!, style: textTheme.bodyMedium),
          ],
          Gap(Spacing.sm.h),
          Text(explanationText, style: textTheme.bodySmall),
          Gap(Spacing.md.h),
          Text(
            'Based on self-reported Attune activities. This cannot predict chemistry, safety, or relationship success.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Gap(Spacing.md.h),
          Wrap(
            spacing: Spacing.sm.w,
            runSpacing: Spacing.xs.h,
            children: [
              TextButton.icon(
                onPressed: () {
                  _showReportDialog(
                    context,
                    ref,
                    introduction.id,
                    introduction.displayName,
                  );
                },
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Report'),
              ),
              TextButton.icon(
                onPressed: () {
                  _showBlockConfirmation(
                    context,
                    ref,
                    introduction.id,
                    introduction.displayName,
                  );
                },
                icon: const Icon(Icons.block_outlined, size: 18),
                label: const Text('Block'),
              ),
            ],
          ),
          Gap(Spacing.xs.h),
          if (!introduction.hasActed)
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Not for me',
                    onPressed: () {
                      _handleAction(context, ref, introduction.id, 'passed');
                    },
                    size: ButtonSize.small,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'Interested',
                    onPressed: () {
                      _handleAction(
                        context,
                        ref,
                        introduction.id,
                        'interested',
                      );
                    },
                    size: ButtonSize.small,
                  ),
                ),
              ],
            )
          else
            Text(
              'Response recorded privately.',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.primary),
            ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    String introductionId,
    String action,
  ) async {
    // Tactile confirmation the moment the tap lands: a warmer light impact for
    // Interested, a lighter selection tick for a pass. Double-blind is
    // preserved — this fires on the viewer's own action only.
    final haptics = ref.read(hapticsProvider);
    if (action == 'interested') {
      haptics.light();
    } else {
      haptics.selection();
    }
    try {
      await ref.read(
        actOnIntroductionProvider((
          introductionId: introductionId,
          action: action,
        )).future,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'interested'
                  ? 'Interest recorded privately'
                  : 'Pass recorded privately',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to record action: $e')));
      }
    }
  }

  Widget _buildPausedState(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.pause_circle_outline,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            Gap(Spacing.md.h),
            Text(
              'Dating Mode is paused',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Gap(Spacing.sm.h),
            Text(
              'You are hidden from new introduction generation right now.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            AppButton(
              label: 'Resume',
              onPressed: () async {
                await ref.read(resumeDatingProvider.future);
              },
              size: ButtonSize.medium,
            ),
            Gap(Spacing.md.h),
            AppButton(
              label: 'Exit Dating Mode',
              onPressed: () {
                _showExitConfirmation(context, ref);
              },
              size: ButtonSize.medium,
              customColor: colorScheme.surfaceContainerHighest,
              textColor: colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExitedState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.exit_to_app_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            Gap(Spacing.md.h),
            Text(
              'You exited Dating Mode',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Gap(Spacing.sm.h),
            Text(
              'A fresh opt-in is required before you can activate a profile again.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            AppButton(
              label: 'Review consent again',
              onPressed: () {
                context.pushNamed('datingConsent');
              },
              size: ButtonSize.medium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuspendedState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            Gap(Spacing.md.h),
            Text(
              'Dating access is unavailable',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Gap(Spacing.sm.h),
            Text(
              'Your account needs review before Dating Mode can continue.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showExitConfirmation(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Exit Dating Mode?'),
            content: const Text(
              'This hides you from new introductions immediately. Existing matches remain unless you end them separately.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(exitDatingProvider.future);
                },
                child: const Text('Exit'),
              ),
            ],
          ),
    );
  }

  void _showBlockConfirmation(
    BuildContext context,
    WidgetRef ref,
    String introductionId,
    String displayName,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Block $displayName?'),
            content: const Text(
              'Blocking removes this introduction and prevents future pairing.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(
                    blockDatingIntroductionProvider(introductionId).future,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User blocked')),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Block'),
              ),
            ],
          ),
    );
  }

  void _showReportDialog(
    BuildContext context,
    WidgetRef ref,
    String introductionId,
    String displayName,
  ) {
    const categories = <String>[
      'safety_concern',
      'harassment',
      'impersonation',
      'romance_scam',
      'underage_risk',
      'sexual_content',
      'spam',
      'other',
    ];
    final detailsController = TextEditingController();
    String selectedCategory = categories.first;

    showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text('Report $displayName'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        items:
                            categories
                                .map(
                                  (category) => DropdownMenuItem<String>(
                                    value: category,
                                    child: Text(category.replaceAll('_', ' ')),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => selectedCategory = value);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Gap(Spacing.md.h),
                      TextField(
                        controller: detailsController,
                        maxLines: 4,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Details (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await ref.read(
                          reportDatingIntroductionProvider((
                            introductionId: introductionId,
                            category: selectedCategory,
                            details:
                                detailsController.text.trim().isEmpty
                                    ? null
                                    : detailsController.text.trim(),
                          )).future,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Thank you for reporting. We will review it.',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Submit'),
                    ),
                  ],
                ),
          ),
    ).whenComplete(detailsController.dispose);
  }
}
