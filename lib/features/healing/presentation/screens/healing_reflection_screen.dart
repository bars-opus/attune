// lib/features/healing/presentation/screens/healing_reflection_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/quiz/presentation/widgets/number_badge.dart';

import '../providers/healing_providers.dart';

/// Same index order as [_reflectionPrompts]. Mirrors onboarding's
/// personalAnchorPrompts/personalAnchorExamples pattern (see
/// onboarding_models.dart) — every free-text, "answer these in your own
/// words" step in the app shows a heading, the question, the field, then
/// a few examples underneath, so an empty box is never the only starting
/// point. Kept local to this screen rather than promoted to a shared
/// constants file: unlike the onboarding anchors (reused across
/// AnchorsStep, Ask2Flow, and FAQ copy), these prompts have exactly one
/// call site.
const _reflectionPrompts = <String>[
  'What do you want to understand about what happened?',
  'What did you learn about yourself?',
  'What would you like to carry forward?',
];

const _reflectionExamples = <List<String>>[
  [
    'Whether it ended because of something fixable or something fundamental',
    'My part in how things went, not just theirs',
    'Why I stayed as long as I did',
  ],
  [
    'I go quiet instead of saying what I actually need',
    'I mistook intensity for closeness',
    'I\'m more capable of being alone than I thought',
  ],
  [
    'Speaking up earlier instead of waiting until I\'m resentful',
    'That it\'s okay to need reassurance sometimes',
    'A clearer sense of what I won\'t compromise on next time',
  ],
];

class HealingReflectionScreen extends ConsumerStatefulWidget {
  final HealingJourney journey;

  const HealingReflectionScreen({super.key, required this.journey});

  @override
  ConsumerState<HealingReflectionScreen> createState() =>
      _HealingReflectionScreenState();
}

class _HealingReflectionScreenState
    extends ConsumerState<HealingReflectionScreen> {
  // Same shape as AnchorsStep's own `controllers` field — one
  // TextEditingController per prompt, same index order as
  // _reflectionPrompts/_reflectionExamples.
  final _controllers = List.generate(
    _reflectionPrompts.length,
    (_) => TextEditingController(),
  );
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingAnswers();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadExistingAnswers() {
    final answers = widget.journey.reflectionAnswers;
    if (answers.isNotEmpty) {
      for (var i = 0; i < _controllers.length; i++) {
        _controllers[i].text = answers['answer${i + 1}'] ?? '';
      }
    }
  }

  Map<String, String> get _currentAnswers => {
    for (var i = 0; i < _controllers.length; i++)
      'answer${i + 1}': _controllers[i].text,
  };

  Future<void> _saveProgress() async {
    final answers = _currentAnswers;

    setState(() => _isSaving = true);

    try {
      await ref.read(
        updateReflectionProvider((
          journeyId: widget.journey.id,
          answers: answers,
        )).future,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Progress saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _completeStage() async {
    final answers = _currentAnswers;

    // Save first
    setState(() => _isSaving = true);

    try {
      await ref.read(
        updateReflectionProvider((
          journeyId: widget.journey.id,
          answers: answers,
        )).future,
      );

      await ref.read(completeReflectionProvider(widget.journey.id).future);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to complete: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            'Reflection',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          centerTitle: false,
          actions: [
            AppTextButton(
              text: 'Save',
              onPressed: _isSaving ? null : _saveProgress,
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.all(Spacing.lg.w),
          children: [
            InfoRowWidget(
              subtitle:
                  'This is private to you. Your answers will not be shared.',
              title: 'Take a moment to reflect on what you learned.',
              icon: Icons.psychology,
              iconSize: 40.h,
              avatarRadius: 25.h,
              onTap: () {},
              disableTrailing: true,
              showAvatar: false,
              showDivider: false,
              showTrailingArrow: false,
            ),

            // Text(
            //   'Take a moment to reflect on what you learned.',
            //   style: textTheme.headlineSmall?.copyWith(
            //     fontWeight: FontWeight.w600,
            //   ),
            // ),
            // Gap(Spacing.sm.h),
            // Text(
            //   'This is private to you. Your answers will not be shared.',
            //   style: textTheme.bodySmall?.copyWith(
            //     color: colorScheme.onSurface.withValues(alpha: 0.6),
            //   ),
            // ),
            Gap(Spacing.lg.h),
            // AppDivider(),

            // Same per-field shape as onboarding's AnchorsStep (heading,
            // prompt-as-label, field, examples underneath) — see the doc on
            // _reflectionPrompts for why every free-text "answer in your own
            // words" step in the app now looks like this. Unlike
            // OnboardingStepFrame (which AnchorsStep itself uses), this
            // screen builds its own plain Scaffold/ListView rather than the
            // card-deck shell — OnboardingStepFrame requires an ancestor
            // OnboardingDeckScope that only onboarding's own PageView
            // provides, and this is a standalone pushed route with no such
            // ancestor. Reusing it here throws
            // "OnboardingDeckScope.of() called with no scope above it".
            ...List.generate(_reflectionPrompts.length, (index) {
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
                        controller: _controllers[index],
                        label: _reflectionPrompts[index],
                        // The label carries the actual question text here
                        // (see AnchorsStep-matching layout above), not a
                        // short field name — sized up from the default
                        // 14sp so it reads as a heading over the field.
                        labelFontSize: 16.sp,
                        hintText: 'Type your answer',
                        maxLines: 4,
                        maxLength: 500,
                        textInputAction:
                            index == _reflectionPrompts.length - 1
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
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Gap(Spacing.xs.h),
                          ..._reflectionExamples[index].map(
                            (example) => Padding(
                              padding: EdgeInsets.only(bottom: Spacing.xs.h),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '•  ',
                                    style: textTheme.headlineLarge?.copyWith(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      example,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
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
                  ],
                ),
              );
            }),
          ],
        ),
        bottomNavigationBar: Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Skip for now',
                onPressed: () => Navigator.pop(context),
                size: ButtonSize.medium,
                customColor: colorScheme.surfaceContainerHighest,
                textColor: colorScheme.onSurface,
              ),
            ),
            Gap(Spacing.md.w),
            Expanded(
              child: AppButton(
                label: 'Complete reflection →',
                onPressed: _isSaving ? null : _completeStage,
                size: ButtonSize.medium,
                isLoading: _isSaving,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
