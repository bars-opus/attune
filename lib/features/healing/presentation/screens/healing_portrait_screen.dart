// lib/features/healing/presentation/screens/healing_portrait_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/services/healing_generation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/healing_providers.dart';

class HealingPortraitScreen extends ConsumerStatefulWidget {
  final HealingJourney journey;

  const HealingPortraitScreen({super.key, required this.journey});

  @override
  ConsumerState<HealingPortraitScreen> createState() =>
      _HealingPortraitScreenState();
}

class _HealingPortraitScreenState extends ConsumerState<HealingPortraitScreen> {
  final TextEditingController _reflectionController = TextEditingController();
  bool _isGenerating = false;
  String? _portrait;
  String? _reflectionPrompt;
  bool _isComplete = false;
  bool _hasSkipped = false;

  @override
  void initState() {
    super.initState();
    _checkExistingStatus();
  }

  void _checkExistingStatus() {
    if (widget.journey.portraitStatus == 'completed') {
      setState(() {
        _portrait = widget.journey.portraitText;
        _reflectionController.text = widget.journey.portraitReflection ?? '';
        _reflectionPrompt = widget.journey.portraitPrompt;
        _isComplete = true;
      });
    } else if (widget.journey.portraitStatus == 'skipped' ||
        widget.journey.portraitStatus == 'insufficient_evidence') {
      setState(() {
        _hasSkipped = true;
        _isComplete = true;
      });
    }
  }

  Future<void> _generatePortrait() async {
    setState(() => _isGenerating = true);

    try {
      final service = HealingGenerationService(
        supabase: ref.read(supabaseClientProvider),
      );

      final result = await service.generatePortrait(
        journeyId: widget.journey.id,
      );

      if (result != null && result['status'] == 'completed') {
        setState(() {
          _portrait = result['portrait'];
          _reflectionPrompt = result['reflection_prompt'] as String?;
          _isComplete = true;
          _isGenerating = false;
        });
      } else {
        await ref.read(
          completePortraitProvider((
            journeyId: widget.journey.id,
            status: 'insufficient_evidence',
            portraitText: null,
            portraitReflection: null,
            reflectionPrompt: null,
          )).future,
        );

        setState(() {
          _isComplete = true;
          _hasSkipped = true;
          _isGenerating = false;
        });
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate: $e')));
      }
    }
  }

  Future<void> _saveAndComplete() async {
    setState(() => _isGenerating = true);

    try {
      await ref.read(
        completePortraitProvider((
          journeyId: widget.journey.id,
          status: 'completed',
          portraitText: _portrait,
          portraitReflection:
              _reflectionController.text.isNotEmpty
                  ? _reflectionController.text
                  : null,
          reflectionPrompt: _reflectionPrompt,
        )).future,
      );

      if (mounted) {
        setState(() => _isGenerating = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<void> _skipStage() async {
    await ref.read(
      completePortraitProvider((
        journeyId: widget.journey.id,
        status: 'skipped',
        portraitText: null,
        portraitReflection: null,
        reflectionPrompt: null,
      )).future,
    );

    if (mounted) {
      setState(() {
        _hasSkipped = true;
        _isComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal pattern portrait'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stage 4 of 5',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            Text(
              'Your personal pattern portrait',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),

            if (_isGenerating) ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    Gap(Spacing.md.h),
                    Text(
                      'Creating your portrait...',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ] else if (_isComplete && _portrait != null) ...[
              Gap(Spacing.xl.h),
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How you show up in relationships:',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Gap(Spacing.md.h),
                    Text(_portrait!, style: textTheme.bodyLarge),
                  ],
                ),
              ),
              Gap(Spacing.xl.h),
              Text(
                _reflectionPrompt ?? 'What part of this feels familiar?',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Gap(Spacing.sm.h),
              AppTextFormField(
                controller: _reflectionController,
                label: '',
                hintText: 'Write your thoughts here...',
                maxLines: 3,
                maxLength: 500,
              ),
            ] else if (_isComplete && _hasSkipped) ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 48,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    Gap(Spacing.md.h),
                    Text(
                      'No portrait available yet.',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Gap(Spacing.sm.h),
                    Text(
                      'Continue at your own pace.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ] else ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Ready to see a grounded portrait of your relationship tendencies?',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Gap(Spacing.md.h),
                    Text(
                      'A warm synthesis of how you show up in relationships.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],

            Gap(Spacing.md.h),

            if (_isComplete && _portrait != null) ...[
              AppButton(
                label: 'Save portrait →',
                onPressed: _isGenerating ? null : _saveAndComplete,
                size: ButtonSize.medium,
                isLoading: _isGenerating,
              ),
            ] else if (!_isComplete) ...[
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Skip',
                      onPressed: _isGenerating ? null : _skipStage,
                      size: ButtonSize.medium,
                      customColor: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                  Gap(Spacing.md.w),
                  Expanded(
                    child: AppButton(
                      label: 'Generate portrait',
                      onPressed: _isGenerating ? null : _generatePortrait,
                      size: ButtonSize.medium,
                      isLoading: _isGenerating,
                    ),
                  ),
                ],
              ),
            ] else ...[
              AppButton(
                label: 'Continue →',
                onPressed: () => Navigator.pop(context, true),
                size: ButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
