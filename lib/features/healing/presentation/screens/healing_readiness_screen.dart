// lib/features/healing/presentation/screens/healing_readiness_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HealingReadinessScreen extends ConsumerStatefulWidget {
  final HealingJourney journey;

  const HealingReadinessScreen({super.key, required this.journey});

  @override
  ConsumerState<HealingReadinessScreen> createState() =>
      _HealingReadinessScreenState();
}

class _HealingReadinessScreenState
    extends ConsumerState<HealingReadinessScreen> {
  final Map<String, dynamic> _answers = {};
  bool _isSubmitting = false;
  Map<String, dynamic>? _result;
  static const List<String> _scaleLabels = [
    'Not at all',
    'A little',
    'Somewhat',
    'Mostly',
    'Completely',
  ];

  final List<Map<String, dynamic>> _questions = [
    {'key': 'q1', 'text': 'I have made space to reflect on the relationship.'},
    {
      'key': 'q2',
      'text':
          'I can describe my own part in the relationship dynamic without taking all the blame.',
    },
    {
      'key': 'q3',
      'text':
          'I can name qualities and boundaries that matter to me in a future relationship.',
    },
    {
      'key': 'q4',
      'text':
          'Interest in meeting someone new feels like a choice, not only an escape from this ending.',
    },
    {
      'key': 'q5',
      'text':
          'Thoughts about the ending feel manageable enough for everyday life.',
    },
    {
      'key': 'q6',
      'text':
          'I feel curious, rather than pressured, about meeting someone new.',
    },
    {
      'key': 'q7',
      'text': 'I can spend time on my own without it deciding my worth.',
    },
  ];

  bool get _allAnswered =>
      _questions.every((q) => _answers.containsKey(q['key']));

  Future<void> _submitReadiness() async {
    if (!_allAnswered || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await ref.read(
        submitReadinessProvider((
          journeyId: widget.journey.id,
          answers: Map.from(_answers),
        )).future,
      );

      setState(() {
        _result = result;
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
      }
    }
  }

  Widget _buildScaleRow(String key, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currentValue = _answers[key] as int?;

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: textTheme.bodyMedium),
          Gap(Spacing.md.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (index) {
              final value = index + 1;
              final isSelected = currentValue == value;
              final label = _scaleLabels[index];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _answers[key] = value;
                  });
                },
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            isSelected
                                ? colorScheme.primary.withValues(alpha: 0.2)
                                : Colors.transparent,
                        border: Border.all(
                          color:
                              isSelected
                                  ? colorScheme.primary
                                  : colorScheme.outline.withValues(alpha: 0.3),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$value',
                          style: TextStyle(
                            fontWeight:
                                isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                            color: isSelected ? colorScheme.primary : null,
                          ),
                        ),
                      ),
                    ),
                    Gap(Spacing.xs.h),
                    Text(
                      label,
                      style: textTheme.labelSmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_result != null) {
      return _buildResultScreen(colorScheme, textTheme);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Readiness check-in'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stage 5 of 5',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            Text(
              'Check in with yourself',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'This check-in reflects your answers today. It cannot determine whether you are healed or ready.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Gap(Spacing.xl.h),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children:
                      _questions.map((q) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: Spacing.md.h),
                          child: _buildScaleRow(q['key'], q['text']),
                        );
                      }).toList(),
                ),
              ),
            ),

            Gap(Spacing.md.h),

            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Complete without score',
                    onPressed:
                        _isSubmitting
                            ? null
                            : () async {
                              setState(() => _isSubmitting = true);
                              try {
                                await ref.read(
                                  completeReadinessWithoutScoreProvider(
                                    widget.journey.id,
                                  ).future,
                                );
                                if (!context.mounted) return;
                                Navigator.pop(context, true);
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to complete: $e'),
                                  ),
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _isSubmitting = false);
                                }
                              }
                            },
                    size: ButtonSize.medium,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'Submit',
                    onPressed:
                        _allAnswered && !_isSubmitting
                            ? _submitReadiness
                            : null,
                    size: ButtonSize.medium,
                    isLoading: _isSubmitting,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultScreen(ColorScheme colorScheme, TextTheme textTheme) {
    final score = _result?['score'] as int? ?? 0;
    final isEligible = _result?['is_eligible'] as bool? ?? false;
    final message = _result?['message'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Check-in complete'), centerTitle: true),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    isEligible
                        ? colorScheme.primary.withValues(alpha: 0.1)
                        : colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.3,
                        ),
                border: Border.all(
                  color:
                      isEligible
                          ? colorScheme.primary
                          : colorScheme.outline.withValues(alpha: 0.2),
                  width: 4,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$score',
                      style: textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isEligible ? colorScheme.primary : null,
                      ),
                    ),
                    Text(
                      'Check-in score',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Gap(Spacing.xl.h),
            Text(
              message,
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),
            Text(
              'Scoring version: healing_readiness_v1_1',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
            Gap(Spacing.xl.h),
            Text(
              'This is a self-reflection indicator, not a clinical assessment.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            AppButton(
              label:
                  isEligible
                      ? 'Continue to journey completion →'
                      : 'Back to journey',
              onPressed:
                  () => Navigator.popUntil(context, (route) => route.isFirst),
              size: ButtonSize.medium,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
