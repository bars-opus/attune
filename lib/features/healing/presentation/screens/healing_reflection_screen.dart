// lib/features/healing/presentation/screens/healing_reflection_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/healing_providers.dart';

class HealingReflectionScreen extends ConsumerStatefulWidget {
  final HealingJourney journey;

  const HealingReflectionScreen({super.key, required this.journey});

  @override
  ConsumerState<HealingReflectionScreen> createState() =>
      _HealingReflectionScreenState();
}

class _HealingReflectionScreenState
    extends ConsumerState<HealingReflectionScreen> {
  final TextEditingController _answer1Controller = TextEditingController();
  final TextEditingController _answer2Controller = TextEditingController();
  final TextEditingController _answer3Controller = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingAnswers();
  }

  @override
  void dispose() {
    _answer1Controller.dispose();
    _answer2Controller.dispose();
    _answer3Controller.dispose();
    super.dispose();
  }

  void _loadExistingAnswers() {
    final answers = widget.journey.reflectionAnswers;
    if (answers.isNotEmpty) {
      _answer1Controller.text = answers['answer1'] ?? '';
      _answer2Controller.text = answers['answer2'] ?? '';
      _answer3Controller.text = answers['answer3'] ?? '';
    }
  }

  Future<void> _saveProgress() async {
    final answers = {
      'answer1': _answer1Controller.text,
      'answer2': _answer2Controller.text,
      'answer3': _answer3Controller.text,
    };

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
    final answers = {
      'answer1': _answer1Controller.text,
      'answer2': _answer2Controller.text,
      'answer3': _answer3Controller.text,
    };

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reflection'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveProgress,
            tooltip: 'Save progress',
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stage 1 of 5',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            Text(
              'Take a moment to reflect on what you learned.',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'This is private to you. Your answers will not be shared.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Gap(Spacing.xl.h),

            // Question 1
            Text(
              'What do you want to understand about what happened?',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _answer1Controller,
              label: '',
              hintText: 'Write your thoughts here...',
              maxLines: 3,
              maxLength: 500,
            ),
            Gap(Spacing.lg.h),

            // Question 2
            Text(
              'What did you learn about yourself?',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _answer2Controller,
              label: '',
              hintText: 'Write your thoughts here...',
              maxLines: 3,
              maxLength: 500,
            ),
            Gap(Spacing.lg.h),

            // Question 3
            Text(
              'What would you like to carry forward?',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _answer3Controller,
              label: '',
              hintText: 'Write your thoughts here...',
              maxLines: 3,
              maxLength: 500,
            ),

            const Spacer(),

            Row(
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
          ],
        ),
      ),
    );
  }
}
