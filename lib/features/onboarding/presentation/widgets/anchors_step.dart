import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
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
    final prompts =
        mode == OnboardingMode.couples
            ? relationshipAnchorPrompts
            : personalAnchorPrompts;

    return OnboardingStepFrame(
      title:
          mode == OnboardingMode.couples
              ? 'Relationship anchors'
              : 'Personal anchors',
      icon: Icons.anchor_outlined,
      subtitle: 'These answers give Attune its first real context.',
      child: Column(
        children: [
          // A plain (non-scrolling, shrink-wrapping) list: the card surface
          // already wraps this whole child in a SingleChildScrollView, so the
          // fields scroll with the rest of the content. A nested scrollable
          // (ListView) or an Expanded here would demand a bounded height the
          // scroll fallback never provides — that was the MISSING-constraints
          // crash. Every sibling step follows this same fixed-Gap pattern.
          ...List.generate(prompts.length, (index) {
            return Padding(
              padding: EdgeInsets.only(bottom: index == prompts.length - 1 ? 0 : Spacing.md.h),
              child: AppTextFormField(
                controller: controllers[index],
                label: 'Anchor ${index + 1}',
                hintText: prompts[index],
                maxLines: 4,
                textInputAction:
                    index == prompts.length - 1
                        ? TextInputAction.done
                        : TextInputAction.next,
              ),
            );
          }),
          Gap(Spacing.xl.h),
          AppButton(
            label: 'Continue',
            onPressed: () => _submit(context),
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
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
