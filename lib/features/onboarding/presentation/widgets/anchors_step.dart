import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/quiz/presentation/widgets/number_badge.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

class AnchorsStep extends StatelessWidget {
  const AnchorsStep({
    super.key,
    required this.mode,
    required this.controllers,
    required this.onNext,
  });

  final OnboardingMode mode;
  final List<TextEditingController> controllers;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prompts =
        mode == OnboardingMode.couples
            ? relationshipAnchorPrompts
            : personalAnchorPrompts;
    final examples =
        mode == OnboardingMode.couples
            ? relationshipAnchorExamples
            : personalAnchorExamples;

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: OnboardingStepFrame(
        title:
            mode == OnboardingMode.couples
                ? 'Relationship anchors'
                : 'Personal anchors',
        icon: Icons.anchor_outlined,
        subtitle: 'These answers give Attune its first real context.',
        child: Column(
          children: [
            AppDivider(), Gap(Spacing.xl.h),
            // A plain (non-scrolling, shrink-wrapping) list: the card surface
            // already wraps this whole child in a SingleChildScrollView, so the
            // fields scroll with the rest of the content. A nested scrollable
            // (ListView) or an Expanded here would demand a bounded height the
            // scroll fallback never provides — that was the MISSING-constraints
            // crash. Every sibling step follows this same fixed-Gap pattern.
            ...List.generate(prompts.length, (index) {
              return CardInkWell(
                child: Column(
                  children: [
                    Gap(Spacing.md.h),
                    NumberBadge(number: index + 1, tag: index.toString()),
                    Gap(Spacing.md.h),
                    Padding(
                      padding: EdgeInsets.only(bottom: Spacing.sm.h),
                      child: AppTextFormField(
                        fillColor: colorScheme.neutral,
                        labelFontSize: 18.sp,
                        controller: controllers[index],
                        label: '${prompts[index]}\n',
                        hintText: 'Type your answer',
                        maxLines: 4,
                        textInputAction:
                            index == prompts.length - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: Spacing.sm.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Examples',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Gap(Spacing.xs.h),
                          ...examples[index].map(
                            (example) => Padding(
                              padding: EdgeInsets.only(bottom: Spacing.xs.h),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '•  ',
                                    style: theme.textTheme.headlineLarge
                                        ?.copyWith(
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      example,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Gap(Spacing.xl.h),
                  ],
                ),
              );
            }),
            Gap(Spacing.xl.h),
            AppButton(
              label: 'Continue',
              textColor: colorScheme.surface,
              onPressed: () => _submit(context),
              size: ButtonSize.small,
              height: OnboardingTokens.actionButtonHeight.h,
            ),
          ],
        ),
      ),
    );
  }

  void _submit(BuildContext context) {
    final hasEmptyAnswer = controllers.any((c) => c.text.trim().isEmpty);
    if (hasEmptyAnswer) {
      context.showErrorSnackbar('Answer all three anchors to continue.');
      return;
    }
    onNext();
  }
}
