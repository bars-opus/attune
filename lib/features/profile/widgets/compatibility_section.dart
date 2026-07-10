// lib/features/profile/presentation/widgets/compatibility_section.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/attachment_compatibility.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/quiz/presentation/screens/partner_quiz_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class CompatibilitySection extends ConsumerWidget {
  const CompatibilitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compatibilityAsync = ref.watch(refreshedAttachmentCompatibilityProvider);

    final isInCouplesMode =
        ref.watch(userRelationshipModeProvider).valueOrNull == 'couples';

    if (!isInCouplesMode) {
      return const SizedBox.shrink();
    }

    // Add a listener to show toast when compatibility updates
    ref.listen<
      AsyncValue<AttachmentCompatibility?>
    >(refreshedAttachmentCompatibilityProvider, (previous, next) {
      if (previous?.value != null &&
          next.value != null &&
          previous?.value?.pairingName != next.value?.pairingName) {
        // Compatibility was updated due to a retake
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your compatibility insight has been updated based on new results',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });

    return compatibilityAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (compatibility) {
        if (compatibility == null) {
          return _buildWaitingState(context, ref);
        }

        return Container(
          padding: EdgeInsets.all(Spacing.md.w),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your attachment pairing',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Gap(Spacing.md.h),

              // User and partner types
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(Spacing.sm.w),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.sm.r,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'You',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            compatibility.userType,
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Gap(Spacing.md.w),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(Spacing.sm.w),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.sm.r,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            compatibility.partnerName,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            compatibility.partnerType,
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Gap(Spacing.lg.h),

              // Pairing name
              Text(
                compatibility.pairingName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Gap(Spacing.sm.h),

              // Pairing description
              Text(
                compatibility.pairingDescription,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Gap(Spacing.md.h),

              // Natural strength
              Row(
                children: [
                  Icon(
                    Icons.favorite,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  Gap(Spacing.sm.w),
                  Expanded(
                    child: Text(
                      compatibility.naturalStrength,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              Gap(Spacing.sm.h),

              // Watch area
              Row(
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  Gap(Spacing.sm.w),
                  Expanded(
                    child: Text(
                      compatibility.watchArea,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              Gap(Spacing.lg.h),

              // View full compatibility button
              AppButton(
                label: 'View full compatibility →',
                onPressed: () {
                  _showFullCompatibility(context, ref, compatibility);
                },
                size: ButtonSize.medium,
                width: double.infinity,
                customColor: Colors.transparent,
                textColor: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWaitingState(BuildContext context, WidgetRef ref) {
    final bothShared =
        ref.watch(bothPartnersSharedProvider).valueOrNull ?? false;

    if (!bothShared) {
      return Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        ),
        child: Column(
          children: [
            Icon(
              Icons.lock_outline,
              size: 32,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            Gap(Spacing.md.h),
            Text(
              'Attachment compatibility will appear here',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),
            Text(
              'when both of you have shared your results.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _showFullCompatibility(
    BuildContext context,
    WidgetRef ref,
    AttachmentCompatibility compatibility,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder:
                (context, scrollController) => Container(
                  padding: EdgeInsets.all(Spacing.lg.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attachment compatibility',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Gap(Spacing.md.h),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                compatibility.pairingName,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Gap(Spacing.md.h),
                              Text(
                                compatibility.pairingDescription,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              Gap(Spacing.xl.h),
                              Text(
                                'Natural strength',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Gap(Spacing.sm.h),
                              Text(compatibility.naturalStrength),
                              Gap(Spacing.lg.h),
                              Text(
                                'Area to watch',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Gap(Spacing.sm.h),
                              Text(compatibility.watchArea),
                              Gap(Spacing.xl.h),
                              Text(
                                'Want to learn more about your partner\'s style?',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Gap(Spacing.md.h),
                              Row(
                                children: [
                                  Expanded(
                                    child: AppButton(
                                      label: 'View partner\'s result',
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) => PartnerQuizResultScreen(
                                                  quizType: 'attachment',
                                                  partnerId:
                                                      compatibility.partnerId,
                                                ),
                                          ),
                                        );
                                      },
                                      size: ButtonSize.medium,
                                      customColor:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                      textColor:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }
}
